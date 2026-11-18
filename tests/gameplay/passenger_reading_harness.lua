-- SPDX-License-Identifier: MIT
-- Exercise the production reading transaction and supervisor as its native
-- passenger changes world position, seat, vehicle or driver role.
local SC = SurvivorCompanion
local D, S = SC.Downtime, SC.ActionSupervisor
local choose = D._readingForTests()
local _, _, _, begin, _, _, _, _, _, _, _, stateFor = D._furnitureForTests()
local quiet = { snapshot = { threatCount=0, immediateCount=0 } }
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'passenger reading ' .. checks .. ': ' .. message)
end
local function trip(name)
    local book = SC_READING_BOOK(name)
    local reader = SC_READING_ACTOR('passenger:' .. name, {book})
    local driver = SC_READING_ACTOR('driver:' .. name, {})
    local car = { seats={[reader]=1, [driver]=0}, driver=driver }
    function car:getSeat(who) return self.seats[who] or -1 end
    function car:isDriver(who) return self.driver == who end
    function car:getDriver() return self.driver end
    reader.vehicle, driver.vehicle = car, car
    reader.commands.order = 'follow'
    return reader, driver, car, book
end
local function start(reader, book)
    local activity = assert(choose(reader, {book}))
    SC_READING_RANDOM.values = {60000}
    local accepted, why = begin(reader, stateFor(reader), activity,
        reader.commands, SC_READING_CLOCK)
    check(accepted, 'reading starts: ' .. tostring(why))
    return assert(S.current(reader)), activity
end
local function pages(reader, book)
    return (reader.data.SC_ReadingPages or {})[book:getFullType()] or 0
end
local function cancelled(reader, book, reason)
    check(S.current(reader) == nil and D.peek(reader).active == nil
        and reader.visual == nil and pages(reader, book) == 0
        and book.container == reader.inventory,
        'interruption releases ownership without pages or lost book: ' .. reason)
end

do
    local reader, driver, car, book = trip('moving')
    check(D.canReadOnTrip(reader, driver), 'a passenger with a carried book can read')
    check(not D.canReadOnTrip(driver, reader), 'the driver cannot read')
    local token, activity = start(reader, book)
    for index=1,12 do
        reader.x, reader.y = reader.x+4, reader.y+2
        driver.x, driver.y = driver.x+4, driver.y+2
        SC_READING_CLOCK = SC_READING_CLOCK+1000
        S.update(reader)
        D.update(reader, driver, quiet, 'read')
        check(S.current(reader) == token and pages(reader, book) == 0,
            'vehicle-carried motion preserves the chapter without early credit')
    end
    SC_READING_CLOCK = activity.startedAt + activity.durationMs
    S.update(reader)
    D.update(reader, driver, quiet, 'read')
    check(S.current(reader) == nil and D.peek(reader).active == nil
        and pages(reader, book) == 5 and car:getSeat(reader) == 1,
        'one completed moving-passenger chapter grants exactly one page reward')
    S.update(reader)
    check(pages(reader, book) == 5, 'a completed chapter cannot be credited twice')
end

for _, change in ipairs({'exit','seat','vehicle','driver','unreadable_seat'}) do
    local reader, driver, car, book = trip(change)
    start(reader, book)
    if change == 'exit' then reader.vehicle = nil
    elseif change == 'seat' then car.seats[reader] = 2
    elseif change == 'vehicle' then reader.vehicle = {}
    elseif change == 'driver' then car.driver = reader
    else function car:getSeat() error('native seat unavailable') end end
    SC_READING_CLOCK = SC_READING_CLOCK+500
    S.update(reader)
    cancelled(reader, book, change)
    check(S.summary(reader, true).lastFailure.reason == 'passenger_read_interrupted',
        'a changed or unverified passenger pose has an explicit interruption reason')
end

do
    local reader = SC_READING_ACTOR('reader:on-foot', {SC_READING_BOOK('Foot')})
    local book = reader.inventory.items[1]
    start(reader, book)
    reader.x = reader.x+1
    S.update(reader)
    cancelled(reader, book, 'walking away')
    check(S.summary(reader, true).lastFailure.reason == 'protected_pose_moved',
        'ordinary on-foot reading keeps its original displacement guard')
end

do
    local reader = trip('other-work')
    local token = assert(S.begin(reader, {owner='work',action='loot_container',
        protectedPose=true,passengerPose=true}))
    reader.x = reader.x+1
    S.update(reader)
    check(not S.isCurrent(token)
        and S.summary(reader,true).lastFailure.reason == 'protected_pose_moved',
        'the passenger exception cannot weaken other work transactions')
end

for _, cause in ipairs({'danger','new_order','deadline'}) do
    local reader, driver, car, book = trip(cause)
    local token = start(reader, book)
    if cause == 'danger' then
        D.update(reader, driver, {snapshot={immediateCount=1}}, 'read')
    elseif cause == 'new_order' then
        reader.commands.commandSerial = reader.commands.commandSerial+1
        D.update(reader, driver, quiet, 'read')
    else
        reader.visual.stalled = true
        SC_READING_CLOCK = SC_READING_CLOCK+token.deadlines.animating+1
        S.update(reader)
    end
    cancelled(reader, book, cause)
end
SC_TEST_REPORT = 'PASSENGER_READING_PASS checks=' .. checks
