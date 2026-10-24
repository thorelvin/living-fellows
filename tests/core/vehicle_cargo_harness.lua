-- SPDX-License-Identifier: MIT
-- Exact native part/container selection, independent of vehicle brand or id.
local SC, checks = SurvivorCompanion, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "vehicle cargo check " .. checks .. ": " .. message)
end
local function part(id, capacity, category, area, seat)
    local value = { id = id, category = category or "bodywork", area = area or "TruckBed",
        seat = seat == true, container = { capacity = capacity } }
    function value:getId() return self.id end
    function value:getCategory() return self.category end
    function value:getArea() return self.area end
    function value:isSeat() return self.seat end
    function value:getItemContainer() return self.container end
    function value.container:getCapacity() return self.capacity end
    function value.container:getEffectiveCapacity() return math.max(1, math.floor(self.capacity * 1.3)) end
    return value
end
local function car(parts, areas)
    local value = { parts = parts, accessCalls = 0, reads = 0 }
    local script = { areas = areas or { TruckBed = {}, Roofrack = {}, CargoRear = {} } }
    function script:getAreaById(id) return self.areas[id] end
    function value:getScript() return script end
    function value:getPartCount() return #self.parts end
    function value:getPartByIndex(index)
        self.reads = self.reads + 1
        return self.parts[index + 1]
    end
    function value:canAccessContainer()
        self.accessCalls = self.accessCalls + 1
        error("remote cargo selection must not demand physical approach")
    end
    function value:getPartById() error("cargo selection must enumerate actual parts") end
    return value
end
local function selected(vehicle) return SC.Vehicle.cargoPart(vehicle) end
local seat = part("SeatFrontRight", 20, "seats", "CargoRear", true)
local glove = part("GloveBox", 7, "bodywork", "CargoRear")
local hidden = part("HiddenCargo", 1000, "nodisplay")
local dummy = part("TruckBed", 0, "nodisplay")
local actual = part("F3502Trunk", 155, "bodywork", "TruckBed")
local roof = part("RoofRackCargo", 80, "bodywork", "Roofrack")
local vehicle = car({ dummy, seat, glove, hidden, roof, actual })
local chosen, container, reason = selected(vehicle)
check(chosen == actual and container == actual.container and reason == nil,
    "the real155-capacity modded trunk wins over its hidden TruckBed placeholder and roof rack")
check(dummy.container:getEffectiveCapacity() == 1 and chosen ~= dummy,
    "Organized's effective one-slot zero-capacity dummy is never real cargo")
check(vehicle.accessCalls == 0,
    "remote selection does not use a proximity-dependent canAccessContainer test")
local arbitrary = part("CustomStorageModule", 155, "bodywork", "CargoRear")
check(selected(car({ dummy, arbitrary })) == arbitrary,
    "a cargo area works under an arbitrary part id without vehicle-specific names")
local vanilla = part("TruckBed", 80)
check(selected(car({ actual, vanilla })) == vanilla,
    "a real visible vanilla TruckBed remains the preferred cargo container")
local hiddenPositive = part("TruckBed", 80, "hidden")
check(selected(car({ hiddenPositive, actual })) == actual,
    "a hidden positive-capacity TruckBed cannot outrank actual visible cargo")
local noArea = part("TrunkWithoutArea", 90)
noArea.area = ""
check(selected(car({ noArea, actual })) == actual,
    "a cargo placeholder without an approach area is ignored")
local invalidArea = part("TrunkInvalidArea", 90, "bodywork", "MissingArea")
check(selected(car({ invalidArea, actual })) == actual,
    "a named area absent from the vehicle script is not a valid cargo approach")
local zeroVisible = part("CargoZero", 0, "bodywork")
check(selected(car({ zeroVisible, actual })) == actual,
    "visible zero-capacity parts are excluded independently of hidden category")
local renamedGlove = part("FrontStorage", 7, "bodywork", "GloveBox")
check(selected(car({ renamedGlove, actual }, { TruckBed = {}, GloveBox = {} })) == actual,
    "a renamed glovebox is excluded by its native approach area")
local first, second = part("CargoFirst", 30), part("CargoSecond", 200)
check(selected(car({ first, second })) == first,
    "equally classified cargo uses deterministic native part order instead of changing by free room")
local emptyPart, emptyContainer, emptyReason = selected(car({ seat, glove, hidden, dummy }))
check(emptyPart == nil and emptyContainer == nil and emptyReason == "car_trunk_missing",
    "seat, glovebox and hidden containers alone do not make a cargo trunk")
local missingPart, missingContainer, missingReason = selected({})
check(missingPart == nil and missingContainer == nil and missingReason == "car_cargo_unavailable",
    "missing enumeration is reported as unavailable rather than choosing a guessed part")
local oversized = car({ actual })
function oversized:getPartCount() return 513 end
check(select(3, selected(oversized)) == "car_cargo_unavailable" and oversized.reads == 0,
    "corrupt oversized enumeration is bounded before scanning")
SC_TEST_REPORT = "VEHICLE_CARGO_PASS checks=" .. checks
