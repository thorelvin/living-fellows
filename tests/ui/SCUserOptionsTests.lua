-- SPDX-License-Identifier: MIT

local user = SurvivorCompanion.UserOptions
local api = PZAPI.ModOptions
local group = api:getOptions("SurvivorCompanion")

assert(group ~= nil and #group.data == 4, "four built-in options registered")
assert(user.get("chatter") == "normal", "chatter default before load")
assert(user.get("coughSneezes") == "normal", "cough default before load")
assert(user.get("ordinaryColds") == true, "ordinary colds default before load")
assert(user.get("protectRecruitedCompanions") == false,
    "friendly-fire protection default before load")

local loaded, reason = user.load()
assert(loaded == true, tostring(reason))
assert(user.get("chatter") == "rare", "saved chatter loaded before runtime")
assert(user.get("coughSneezes") == "rare", "saved cough setting loaded")
assert(user.get("ordinaryColds") == false, "saved cold setting loaded")
assert(user.get("protectRecruitedCompanions") == true,
    "saved player-attack protection loaded")
assert(SCBridge.calls[#SCBridge.calls] == true, "saved protection synced to native gate")
local savedComfort = SCBridge.comfortCalls[#SCBridge.comfortCalls]
assert(savedComfort.mode == "rare" and savedComfort.ordinaryColds == false,
    "saved comfort choices reach the native constructor defaults")
assert(SurvivorCompanion.Gestures.nativeOptionApplies == 1,
    "saved symptom preferences sent to native actors")

-- MainOptions applies widget values, then calls each options:apply() and saves.
group:getOption("chatter"):setValue(2)
group:getOption("coughSneezes"):setValue(3)
group:getOption("ordinaryColds"):setValue(true)
group:getOption("protectRecruitedCompanions"):setValue(false)
group:apply()
assert(user.get("chatter") == "less", "Apply updates chatter live")
assert(user.get("coughSneezes") == "off", "Apply updates coughs live")
assert(user.get("ordinaryColds") == true, "Apply updates colds live")
assert(user.get("protectRecruitedCompanions") == false,
    "Apply updates protection live")
assert(SCBridge.calls[#SCBridge.calls] == false, "Apply updates native gate live")
local liveComfort = SCBridge.comfortCalls[#SCBridge.comfortCalls]
assert(liveComfort.mode == "off" and liveComfort.ordinaryColds == true,
    "Apply updates native constructor defaults live")
assert(SurvivorCompanion.Gestures.nativeOptionApplies == 2,
    "Apply updates existing companions immediately")

api:save()
local disk = SC_TEST_MOD_OPTIONS_DISK()
assert(disk[1] == "combobox|SurvivorCompanion|chatter|2")
assert(disk[2] == "combobox|SurvivorCompanion|coughSneezes|3")
assert(disk[3] == "tickbox|SurvivorCompanion|ordinaryColds|true")
assert(disk[4] == "tickbox|SurvivorCompanion|protectRecruitedCompanions|false")

-- Changing memory and reloading must restore the persisted values.
group:getOption("chatter"):setValue(1)
group:getOption("coughSneezes"):setValue(1)
group:getOption("ordinaryColds"):setValue(false)
group:getOption("protectRecruitedCompanions"):setValue(true)
group:apply()
assert(user.load() == true)
assert(user.get("chatter") == "less")
assert(user.get("coughSneezes") == "off")
assert(user.get("ordinaryColds") == true)
assert(user.get("protectRecruitedCompanions") == false)

SC_TEST_SET_MOD_OPTIONS_DISK({
    "combobox|SurvivorCompanion|chatter|99",
    "combobox|SurvivorCompanion|coughSneezes|0",
})
assert(user.load() == true)
assert(user.get("chatter") == "normal", "invalid chatter index uses default")
assert(user.get("coughSneezes") == "normal", "invalid cough index uses default")

SC_TEST_REPORT = "SCUserOptions persistence and live Apply PASS"
