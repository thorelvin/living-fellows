-- SPDX-License-Identifier: MIT
-- After-death succession. Native player admission and world persistence are
-- separate commits; the journal owns recovery until the player row is durable.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local H={KEY='LF_HandoverV1'} SC.Handover=H
local active,installed,lastError
local function primary() return getSpecificPlayer and getSpecificPlayer(0) end
local function alive(actor) return actor~=nil and SC.GameplayUtil.isDead(actor)~=true end
local function call(object,name,...) return SC.GameplayUtil.call(object,name,...) end
local function data(actor) return actor and SC.GameplayUtil.modData(actor) end
local function journal()
    if not ModData or type(ModData.getOrCreate)~='function' then return nil,'World storage is unavailable.' end
    local value=ModData.getOrCreate(H.KEY)
    if value.schema~=nil and value.schema~=1 then return nil,'This Handover record uses an unsupported format.' end
    if value.schema==nil then value.schema,value.serial,value.retired,value.crew=1,0,{},{} end
    if type(value.retired)~='table' or type(value.crew)~='table' then return nil,'The Handover record is damaged.' end
    return value
end
local function fail(reason)
    reason=tostring(reason or 'Handover could not finish.')
    if lastError~=reason then print('[SurvivorCompanion/handover] '..reason);lastError=reason end
    if active then active.reason=reason end
    return false,reason
end
local function flush()
    local okay,reason=SC.Persistence.save(primary())
    if okay~=true then return fail(reason) end
    local called,result=pcall(SCSplitScreenProbe.flushGlobalModDataForWorldExit)
    if not called or result~=true then return fail(result) end
    return true
end
local function name(actor)
    local desc=actor and select(1,call(actor,'getDescriptor'))
    local first=desc and select(1,call(desc,'getForename')) or 'Survivor'
    local last=desc and select(1,call(desc,'getSurname')) or ''
    return tostring(first)..(last~='' and ' '..tostring(last) or '')
end
local function token(store)
    store.serial=(tonumber(store.serial) or 0)+1
    return 'lf-handover-'..string.format('%.0f',getTimestampMs())..'-'..tostring(ZombRand(1000000000))..'-'..store.serial
end
function H.retired(id)
    local store=journal()
    return store and store.retired[id]~=nil or false
end
function H.current() return active end
function H.pendingReceipt() local store=journal();return store and store.pending end
function H.error() return active and active.reason or lastError end
function H.reportError(reason) return fail(reason) end
function H.isChoosing() return active and (active.phase=='choosing' or active.phase=='creating') or false end
function H.isPaused() return active~=nil and active.phase~='complete' end

function H.begin(player)
    if player==nil or player~=primary() or alive(player) or SC.Actor.isCompanion(player) then return false,'not_primary_death' end
    if isClient and isClient() or isServer and isServer() then return false,'single_player_only' end
    for index=1,3 do
        local other=getSpecificPlayer(index)
        if other and not SC.Actor.isCompanion(other) then return false,'additional_human_players_unsupported' end
    end
    if not SCBridge or type(SCBridge.finalizeHandoverDeath)~='function' then return false,'handover_bridge_unavailable' end
    if SC.Actor.checkBridge then
        local ready,reason=SC.Actor.checkBridge(false)
        if ready~=true then return false,reason end
    end
    if active and active.dead==player then return true end
    local store,why=journal();if not store then return fail(why) end
    active={dead=player,phase='choosing',name=name(player),at=getTimestampMs()}
    store.previous={name=active.name,operator=SC.EmmaMind and SC.EmmaMind.operatorId(player),at=getGameTime():getWorldAgeHours()}
    if SC.EmmaMind and SC.EmmaMind.noteDeath then SC.EmmaMind.noteDeath(player) end
    store.crew=store.crew or {}
    for _,row in pairs(store.crew) do row.helpReported,row.shelterReported,row.nextReportAt=nil,nil,0 end
    for _,record in ipairs(SC.Registry.records()) do
        local order=record.state and record.state.order
        if record.recruited and alive(record.actor) and order and (order.current=='follow' or order.current=='regroup')
            and not (SC.ExpeditionPrototype and SC.ExpeditionPrototype.isMember(record.actor)) then
            local x,y,z=SC.GameplayUtil.position(record.actor)
            if x and not store.crew[record.id] then store.crew[record.id]={id=record.id,x=x,y=y,z=z,serial=order.commandSerial or 0,phase='waiting'} end
        end
    end
    setGameSpeed(0)
    return true
end

function H.options()
    local rows,seen={},{}
    local function add(id,actor,saved)
        if seen[id] or H.retired(id) then return end;seen[id]=true
        if actor and not alive(actor) then return end
        local record=actor and SC.Registry.byId(id)
        if not (record and record.recruited or saved and saved.recruited) then return end
        local identity=saved and saved.identity or {}
        local x,y,z=actor and SC.GameplayUtil.position(actor)
        if actor then x,y,z=SC.GameplayUtil.position(actor) end
        local row={id=id,name=actor and name(actor) or ((identity.forename or 'Survivor')..' '..(identity.surname or '')),
            position=x and {x=x,y=y,z=z} or saved and saved.position,loaded=actor~=nil}
        if actor then
            row.health=select(1,call(select(1,call(actor,'getBodyDamage')),'getOverallBodyHealth'))
            if record.runtime and (record.runtime.inactive or record.runtime.quarantined) then row.reason='This companion has an unresolved recovery problem.'
            elseif SC.PickupService and SC.PickupService.ownsInventory and SC.PickupService.ownsInventory(id) then row.reason='A pickup transfer still owns their inventory.' end
        elseif not SC.Persistence.pendingBootstrap(id) then row.reason='Their saved character is not ready to load.' end
        if not row.reason and SC.HandoverRescue.candidateReason then row.reason=SC.HandoverRescue.candidateReason(id) end
        rows[#rows+1]=row
    end
    for _,record in ipairs(SC.Registry.records()) do add(record.id,record.actor) end
    local store=ModData.getOrCreate(SC.Identity.worldSaveKey)
    for id,saved in pairs(store.document and store.document.companions or {}) do add(id,nil,saved) end
    table.sort(rows,function(a,b) if a.name==b.name then return a.id<b.id end;return a.name<b.name end)
    return rows
end

function H.basePoint()
    local base=SC.BaseLife and SC.BaseLife.active()
    if not base then return nil,'No camp is marked.' end
    local point=SC.BaseLife.zoneCenter('rally') or base.core
    if not point then return nil,'The camp has no arrival point.' end
    local cell=getCell()
    local center=cell and cell:getGridSquare(math.floor(point.x),math.floor(point.y),math.floor(point.z))
    -- Unloaded camp coordinates are streamed and validated before creation.
    if not center then return {x=math.floor(point.x),y=math.floor(point.y),z=math.floor(point.z),baseId=base.id,unloaded=true} end
    for radius=0,16 do for dx=-radius,radius do for dy=-radius,radius do
        if math.max(math.abs(dx),math.abs(dy))==radius then
            local square=cell:getGridSquare(math.floor(point.x)+dx,math.floor(point.y)+dy,math.floor(point.z))
            if square and SC.BaseLife.isInside(square) and square:TreatAsSolidFloor() and not square:isSolid()
                and not square:isSolidTrans() and not square:haveFire() and square:isFree(false) then
                return {x=square:getX(),y=square:getY(),z=square:getZ(),baseId=base.id}
            end
        end
    end end end
    return nil,'No valid arrival tile is available inside the camp.'
end

local function finish()
    local store=assert(journal());local receipt=store.pending
    if not receipt then return fail('Handover receipt is missing.') end
    if receipt.id then store.retired[receipt.id]=receipt.token;store.crew[receipt.id]=nil end
    receipt.phase,receipt.snapshot='complete',nil
    store.last={token=receipt.token,name=name(primary()),previous=store.previous and store.previous.name,kind=receipt.kind}
    store.pending=nil
    if not flush() then store.pending=receipt;return false end
    active=nil;lastError=nil
    if SC.HandoverUI then SC.HandoverUI.close() end
    local death=ISPostDeathUI and ISPostDeathUI.instance[0]
    if death then death:removeFromUIManager();ISPostDeathUI.instance[0]=nil end
    setGameSpeed(1)
    return true
end

local function admit(receipt,recovery)
    local player=SCBridge.prepareHandoverPlayer(receipt.snapshot,receipt.token)
    if recovery then SCBridge.recoverHandoverPlayer(player,receipt.token)
    else SCBridge.admitHandoverPlayer(player) end
    active.phase,active.successor='admitting',player
    return true
end
local function retireSource(actor,receipt)
    if receipt.vehicle then
        local car=select(1,call(actor,'getVehicle'))
        if car then
            if car:getSqlId()~=receipt.vehicle.vehicle.sqlId or car:getSeat(actor)~=receipt.vehicle.seat
                or car:getCharacter(receipt.vehicle.seat)~=actor then return fail('The source vehicle seat changed. Handover remains paused.') end
            -- Ordinary retirement can intentionally preserve a passenger for
            -- vehicle storage. Succession instead releases this exact occupant
            -- after its receipt is durable, before admitting the stock player.
            car:exit(actor)
            if actor:getVehicle()~=nil or car:getCharacter(receipt.vehicle.seat)==actor then return fail('The source vehicle seat has not released.') end
        end
    end
    return SC.Actor.remove(actor)
end

function H.chooseCompanion(id)
    if not active or active.phase~='choosing' then return false,'Choose a successor after death.' end
    local option
    for _,row in ipairs(H.options()) do if row.id==id then option=row;break end end
    if not option then return false,'That living recruit is no longer available.' end
    if option.reason then return false,option.reason end
    if SCBridge.finalizeHandoverDeath(active.dead)~=true then return false,'The previous survivor has not finished dying.' end
    if not option.loaded then
        local okay,why=SC.HandoverRescue.loadCandidate(id)
        if not okay then return fail(why) end
        active.phase,active.loadingId='loading',id
        return true
    end
    local record=SC.Registry.byId(id);local actor=record and record.actor
    if not actor or not alive(actor) then return false,'That companion is no longer alive.' end
    local ready,why=SC.HandoverRescue.prepareChoice(id)
    if not ready then return fail(why) end
    if SC.Trade and SC.Trade.prepareActorLifecycle then
        local settled,reason=SC.Trade.prepareActorLifecycle(actor);if settled~=true then return fail(reason) end
    end
    local cancelled,reason=SC.ActionSupervisor.cancel(actor,'handover')
    if cancelled==false then return fail(reason) end
    if SC.Vehicle and SC.Vehicle.prepareDriverKeyReset then
        local settled,why=SC.Vehicle.prepareDriverKeyReset(actor)
        if settled~=true then return fail(why) end
    end
    local seated=select(1,call(actor,'getVehicle'))
    local vehicle=seated and SC.Vehicle and SC.Vehicle.stateFor(actor) or nil
    if seated and (not vehicle or not vehicle.vehicle or (tonumber(vehicle.vehicle.sqlId) or -1)<0) then
        return false,'This vehicle has not finished saving its seat state.'
    end
    local snapshot=SCBridge.captureHandoverPlayer(actor)
    local store=assert(journal());local receipt={kind='companion',id=id,token=token(store),phase='prepared'}
    local prepared=SCBridge.prepareHandoverPlayer(snapshot,receipt.token)
    receipt.snapshot=SCBridge.captureHandoverPlayer(prepared)
    receipt.vehicle=vehicle
    receipt.name=name(prepared);receipt.x,receipt.y,receipt.z=SC.GameplayUtil.position(prepared)
    store.pending=receipt
    if not flush() then store.pending=nil;return false,H.error() end
    -- From this durable boundary onward recovery completes the same successor.
    receipt.phase='committing';store.retired[id]=receipt.token
    local activity=SC.HandoverRescue.detachCandidate and SC.HandoverRescue.detachCandidate(id)
    if not flush() then
        receipt.phase='prepared';store.retired[id]=nil
        if SC.HandoverRescue.restoreDetached then SC.HandoverRescue.restoreDetached(activity) end
        return false,H.error()
    end
    active.phase='committing'
    local removed,removeWhy=retireSource(actor,receipt)
    if not removed then return fail(removeWhy) end
    SC.BaseLife.restoreResident(id,{present=false})
    if not flush() then return false,H.error() end
    return admit(receipt,false)
end

function H.startNew(normal)
    if not active or active.phase~='choosing' then return false,'Choose a successor after death.' end
    local point,why
    if not normal then point,why=H.basePoint();if not point then return false,why end end
    if SCBridge.finalizeHandoverDeath(active.dead)~=true then return false,'The previous survivor has not finished dying.' end
    local ready,reason=SC.HandoverRescue.prepareChoice()
    if not ready and not normal then return fail(reason) end
    active.phase,active.arrival,active.normal='creating',point,normal==true
    if SC.HandoverUI then SC.HandoverUI.close() end
    local joypad=JoypadState and JoypadState.players and JoypadState.players[1]
    if joypad then CoopCharacterCreation.newPlayer(joypad.id,joypad)
    else CoopCharacterCreation:newPlayerMouse() end
    if point then
        local creator=CoopCharacterCreation.instance
        if creator then
            creator.mapSpawnSelect:useDefaultSpawnRegion();creator.mapSpawnSelect:setVisible(false)
            creator.charCreationProfession:setVisible(true,joypad)
        end
    end
    if setShowPausedMessage then setShowPausedMessage(false) end
    setGameSpeed(0)
    return true
end

function H.cancelCreation()
    if active and active.phase=='creating' then active.phase='choosing';active.arrival=nil;setGameSpeed(0) end
end
function H.creatorPoint() return active and active.phase=='creating' and active.arrival end
function H.noteOrdinaryPoint(point) if active then active.normalPoint=point end end
function H.useOrdinaryArrival()
    local world=journal();local receipt=world and world.pending
    local point=receipt and receipt.normalPoint
    if not active or active.phase~='arrival-blocked' or not point then return false,'An ordinary spawn point is not available.' end
    local player=SCBridge.prepareHandoverPlayer(receipt.snapshot,receipt.token)
    player:setX(point.x+.5);player:setY(point.y+.5);player:setZ(point.z)
    receipt.snapshot=SCBridge.captureHandoverPlayer(player)
    receipt.x,receipt.y,receipt.z=SC.GameplayUtil.position(player)
    receipt.kind,receipt.arrival='normal',nil
    if not flush() then return false,H.error() end
    SCBridge.recoverHandoverPlayer(player,receipt.token)
    active.phase,active.successor,active.arrival='admitting',player,nil
    return true
end
local function readyPlayer(player,receipt)
    if receipt.arrival then
        local square=select(1,call(player,'getCurrentSquare'))
        local base=SC.BaseLife.active()
        local okay=base and base.id==receipt.arrival.baseId and square and SC.BaseLife.isInside(square)
            and square:TreatAsSolidFloor() and not square:isSolid() and not square:isSolidTrans() and not square:haveFire()
        if not okay then
            local point=H.basePoint()
            if not point or point.unloaded or point.baseId~=receipt.arrival.baseId then
                active.phase='arrival-blocked';active.reason='The camp has no valid arrival tile. Choose ordinary spawn or exit.'
                if SC.HandoverUI then SC.HandoverUI.open() end
                return false
            end
            player:teleportTo(point.x,point.y,point.z)
        end
        receipt.arrival=nil
    end
    if receipt.vehicle then
        local car=SC.Vehicle.loadedBySqlId(receipt.vehicle.vehicle.sqlId)
        if not car then return false end
        local seat=receipt.vehicle.seat
        local current=player:getVehicle()
        if current~=car then
            if current or car:getCharacter(seat)~=nil then return fail('The original vehicle seat is not available. Handover remains paused.') end
            car:enter(seat,player)
            car:setCharacterPosition(player,seat,'inside');car:transmitCharacterPosition(seat,'inside');car:playPassengerAnim(seat,'idle')
        end
        if player:getVehicle()~=car or car:getSeat(player)~=seat then return false end
    end
    local md=data(player);local marker=receipt.token..'-ready'
    if md.LF_HandoverReady~=marker then
        md.LF_HandoverReady=marker
        SCBridge.requestHandoverPlayerSave()
    end
    return true
end
function H.greeting()
    local world=journal();local last=world and world.last;local md=data(primary())
    if not last or not md or md.LF_HandoverToken~=last.token or md.LF_HandoverGreeting==last.token then return end
    md.LF_HandoverGreeting=last.token
    return 'Welcome, '..name(primary())..'. '..(last.previous or 'The previous survivor').." didn't make it. I'm still here. We can carry on."
end

function H.reconcile()
    local store,why=journal();if not store then return fail(why) end
    local receipt=store.pending
    if receipt==nil then return true end
    if type(receipt)~='table' then return fail('The pending Handover record is damaged.') end
    if receipt.phase=='prepared' then store.pending=nil;store.retired[receipt.id]=nil;return true end
    if receipt.phase~='committing' and receipt.phase~='complete' then return fail('The pending Handover phase is invalid.') end
    if type(receipt.token)~='string' or receipt.snapshot==nil and receipt.phase~='complete' then return fail('The pending Handover snapshot is missing.') end
    active={phase='recovering',dead=primary(),reason='Finishing the previous Handover.'}
    local md=data(primary())
    if md and md.LF_HandoverToken==receipt.token then active.phase,active.successor='saving',primary()
    elseif receipt.snapshot then admit(receipt,true)
    else return fail('The saved successor does not match the completed Handover.') end
    setGameSpeed(0)
    return true
end

function H.pulse()
    if not active then return end
    setGameSpeed(0)
    local store=assert(journal());local receipt=store.pending
    if SC.HandoverRescue then SC.HandoverRescue.pollPreparation() end
    if active.phase=='loading' then
        if SC.Registry.byId(active.loadingId) then local id=active.loadingId;active.phase='choosing';H.chooseCompanion(id) end
    elseif active.phase=='loading-base' then
        local point=H.basePoint()
        if point and not point.unloaded then active.phase='choosing';H.startNew(false) end
    elseif active.phase=='committing' then
        local record=receipt and SC.Registry.byId(receipt.id)
        if record then
            local okay=retireSource(record.actor,receipt);if not okay then return end
            SC.BaseLife.restoreResident(receipt.id,{present=false})
        end
        if flush() then admit(receipt,false) end
    elseif active.phase=='admitting' or active.phase=='creating' then
        local player=SCBridge.pollHandoverPlayerAdmission()
        if not player or player==active.dead or not alive(player) then return end
        if active.phase=='creating' then
            local md=data(player);md.LF_HandoverToken=token(store)
            receipt={phase='committing',kind=active.normal and 'normal' or 'camp',token=md.LF_HandoverToken,
                snapshot=SCBridge.captureHandoverPlayer(player),name=name(player),arrival=active.arrival,normalPoint=active.normalPoint}
            receipt.x,receipt.y,receipt.z=SC.GameplayUtil.position(player)
            store.pending=receipt
            if not flush() then return end
        end
        active.phase,active.successor='saving',player
        if SC.HandoverUI then SC.HandoverUI.open() end
        readyPlayer(player,receipt)
    elseif active.phase=='saving' then
        if not readyPlayer(primary(),receipt) then return end
        if getTimestampMs()>=(active.savePollAt or 0) then
            active.savePollAt=getTimestampMs()+250
            if SCBridge.handoverPlayerSaved(receipt.token..'-ready') then finish() end
        end
    end
end

function H.install()
    if installed then return true end
    if not Events or not Events.OnPlayerDeath or not Events.OnRenderTick then return false end
    H._death=function(player) local ok,why=pcall(H.begin,player);if not ok then fail(why) end end
    H._render=function()
        local ok,why=pcall(H.pulse);if not ok then fail(why) end
        if not active and SC.HandoverRescue then
            local safe,reason=pcall(SC.HandoverRescue.pulse);if not safe then fail(reason) end
        end
    end
    Events.OnPlayerDeath.Add(H._death);Events.OnRenderTick.Add(H._render)
    installed=true
    return true
end
function H.reset()
    if installed then Events.OnPlayerDeath.Remove(H._death);Events.OnRenderTick.Remove(H._render) end
    active,installed,lastError=nil,nil,nil
end
return H
