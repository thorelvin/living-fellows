-- SPDX-License-Identifier: MIT
-- Exercise the actual world and inventory context hooks with a boarded fare.
require = function() return true end

local function menu()
    local result = { options = {} }
    function result:addOption(label, target, callback, ...)
        local option = { label = label, target = target, callback = callback,
            args = { ... } }
        self.options[#self.options + 1] = option
        return option
    end
    result.addOptionOnTop = result.addOption
    function result:addSubMenu(option, subMenu) option.subMenu = subMenu end
    return result
end
local function option(items, label)
    for _, entry in ipairs(items.options) do
        if entry.label == label then return entry end
    end
    return nil
end
local function check(value, label)
    if not value then error("taxi context: " .. label) end
end

ISContextMenu = { getNew = function() return menu() end }
ISWorldObjectContextMenu = {}
ISInventoryPaneContextMenu = {}
getText = function(key) return key end

local car = {}
local inventory = {}
local player = { car = car, note = nil }
function player:getVehicle() return self.car end
function player:getInventory() return inventory end
function player:setHaloNote(note) self.note = note end
getSpecificPlayer = function(index) return index == 0 and player or nil end
local radio = { container = inventory, radioClass = true, taxiReady = true }
function radio:getContainer() return self.container end
function player:getPrimaryHandItem() return self.primary end
local fareItem = {}
function fareItem:getDisplayName() return "Gold Ring" end

local departCount, offerCount = 0, 0
local phase = "ready_to_depart"
local hasBooking, requestAccepted, requestReason = true, true, "booking_received"
local audio = { plays = {}, stops = {}, active = { [777] = true }, next = 1000 }
function audio:playUISound(name)
    self.next = self.next + 1
    self.plays[#self.plays+1] = name
    self.active[self.next] = true
    return self.next
end
function audio:isPlayingUISound(handle) return self.active[handle] == true end
function audio:stopUISound(handle)
    self.stops[#self.stops+1] = handle
    self.active[handle] = nil
end
getSoundManager = function() return audio end
SurvivorCompanion = {
    GameplayUtil = {
        isZombie = function() return false end,
        instanceOf = function(item, class)
            return item and item.radioClass == true and class == "Radio"
        end,
    },
    TaxiBooking = {
        dispatchReady = true,
        checkRadio = function(_, candidate)
            return candidate == radio and radio.taxiReady
        end,
    },
    TaxiService = {
        current = function() return hasBooking and { phase = phase } or nil end,
        request = function(actor, candidate)
            check(actor == player and candidate == radio, "booking caller and radio")
            return requestAccepted, requestReason
        end,
        status = function() return true, "searching" end,
        cancel = function() return true, "booking_cancelled" end,
        isBookedPassenger = function(actor, vehicle)
            return actor == player and vehicle == car
        end,
        destinations = function(actor, candidate)
            check(actor == player and (candidate == radio or candidate == nil),
                "destination caller")
            return { { id = "base", name = "Home", required = 3 } }
        end,
        depart = function(actor, candidate, destination)
            check(actor == player and (candidate == radio or candidate == nil)
                and destination == "base", "departure parameters")
            departCount = departCount + 1
            return true, "taxi_departed"
        end,
        offer = function(actor, candidate, item)
            check(actor == player and (candidate == radio or candidate == nil)
                and item == fareItem, "fare parameters")
            offerCount = offerCount + 1
            return true, "fare_offered"
        end,
    },
    TaxiCab = {
        looseItems = function(vehicle)
            check(vehicle == car, "fare car")
            return { { item = fareItem, itemType = "Base.GoldRing" } }
        end,
        recover = function() return true, car end,
    },
    TaxiFares = { valueFor = function(item)
        return item == fareItem and 3 or nil
    end },
}

function TaxiContextRun()
local square = { getVehicleContainer = function() return car end }
local object = { getSquare = function() return square end }
local worldMenu = menu()
SurvivorCompanion.UIContext.fillWorldObjectContextMenu(0, worldMenu,
    { object }, false)
local taxi = option(worldMenu, "UI_SC_Taxi_Menu")
check(taxi and taxi.subMenu, "boarded world menu")
check(not option(taxi.subMenu, "UI_SC_Taxi_Status"),
    "hide location request after boarding")
local destination = option(taxi.subMenu, "UI_SC_Taxi_DriveTo")
local fare = option(taxi.subMenu, "UI_SC_Taxi_Offer")
check(destination and fare and option(taxi.subMenu, "UI_SC_Taxi_MapHint"),
    "world menu includes map, destination and fare")
destination.callback(destination.target, unpack(destination.args))
fare.callback(fare.target, unpack(fare.args))
check(departCount == 1 and offerCount == 1,
    "in-car actions work without a radio")

local radioMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0, radioMenu, { radio })
local radioTaxi = option(radioMenu, "UI_SC_Taxi_Menu")
check(radioTaxi and radioTaxi.subMenu, "boarded radio menu")
check(not option(radioTaxi.subMenu, "UI_SC_Taxi_Status"),
    "hide location request in boarded radio menu")
check(option(radioTaxi.subMenu, "UI_SC_Taxi_DriveTo")
    and option(radioTaxi.subMenu, "UI_SC_Taxi_Offer"),
    "radio keeps destination and fare")

phase = "in_transit"
local ridingMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0, ridingMenu, { radio })
check(not option(ridingMenu, "UI_SC_Taxi_Menu"),
    "in-transit radio does not leave an empty taxi submenu")

player.car = nil
local walkingMenu = menu()
SurvivorCompanion.UIContext.fillWorldObjectContextMenu(0, walkingMenu,
    { object }, false)
check(not option(walkingMenu, "UI_SC_Taxi_Menu"),
    "in-car menu unavailable outside cab")

hasBooking = false
local oldExpedition = SurvivorCompanion.ExpeditionPrototype
SurvivorCompanion.ExpeditionPrototype = {current=function() return {scout={search=true}} end}
for _,tvType in ipairs({"Base.TvAntique","Base.TvBlack","Base.TvWideScreen"}) do
    local tv={radioClass=true,container=inventory,fullType=tvType}
    function tv:getContainer() return self.container end
    function tv:getDeviceData() return {getIsTelevision=function() return true end} end
    player.primary=tv
    local televisionMenu=menu()
    SurvivorCompanion.UIContext.fillRadioContextMenu(0,televisionMenu,{tv})
    check(#televisionMenu.options==0,"equipped "..tvType.." has no taxi or expedition transmit menu")
end
SurvivorCompanion.ExpeditionPrototype=oldExpedition player.primary=nil
local receiveOnly={radioClass=true}
local receiverMenu=menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0,receiverMenu,{receiveOnly})
check(not option(receiverMenu,"UI_SC_Taxi_Menu"),"receive-only Radio-class item has no taxi menu")
radio.taxiReady=false
local unpoweredMenu=menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0,unpoweredMenu,{radio})
check(not option(unpoweredMenu,"UI_SC_Taxi_Menu"),"off or otherwise unusable handset has no taxi menu")
radio.taxiReady=true
local mixedMenu=menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0,mixedMenu,{{items={receiveOnly,radio}}})
local mixedRoot=option(mixedMenu,"UI_SC_Taxi_Menu")
local mixedCall=mixedRoot and option(mixedRoot.subMenu,"UI_SC_Taxi_Call")
check(mixedCall and mixedCall.args[2]==radio,"stacked mixed selection binds the working handset")
local bookingMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0, bookingMenu, {radio})
local bookingRoot = option(bookingMenu,"UI_SC_Taxi_Menu")
local book = bookingRoot and option(bookingRoot.subMenu,"UI_SC_Taxi_Call")
check(book ~= nil and #audio.plays == 0, "building the radio menu plays no audio")
local accepted = book.callback(book.target,unpack(book.args))
check(accepted == true and #audio.plays == 1 and audio.plays[1] == "LFTaxiRadioCall",
    "clicking a new accepted booking plays the supplied clip once")
local handle = SurvivorCompanion.UIContext._taxiCallAudio.handle
requestReason = "already_booked"
book.callback(book.target,unpack(book.args))
check(#audio.plays == 1 and SurvivorCompanion.UIContext._taxiCallAudio.handle == handle,
    "stale duplicate booking clicks do not replay or replace the active clip")
hasBooking, phase = true, "searching"
local statusMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0,statusMenu,{radio})
local statusRoot = option(statusMenu,"UI_SC_Taxi_Menu")
local status = option(statusRoot.subMenu,"UI_SC_Taxi_Status")
status.callback(status.target,unpack(status.args))
check(#audio.plays == 1, "status checks do not replay the booking sound")
local cancel = option(statusRoot.subMenu,"UI_SC_Taxi_Cancel")
cancel.callback(cancel.target,unpack(cancel.args))
check(#audio.stops == 1 and audio.stops[1] == handle and audio.active[777],
    "booking cancellation stops only its own call audio")

hasBooking, requestAccepted, requestReason = false, false, "radio_off"
book.callback(book.target,unpack(book.args))
check(#audio.plays == 1, "rejected or switched-off radios make no transmission sound")
requestAccepted, requestReason = true, "booking_received"
book.callback(book.target,unpack(book.args))
local nextHandle = SurvivorCompanion.UIContext._taxiCallAudio.handle
SurvivorCompanion.UIContext.remove()
check(not audio.active[nextHandle] and audio.active[777], "world UI removal releases only the taxi clip")

getSoundManager = function() error("test unavailable audio device") end
accepted = book.callback(book.target,unpack(book.args))
check(accepted == true, "audio device failure cannot reject an accepted taxi booking")

print("taxi context harness passed; booking audio, duplicate/status silence and owned cleanup verified")
end
