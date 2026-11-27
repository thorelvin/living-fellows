-- SPDX-License-Identifier: MIT

local user = LivingFellows.UserOptions
local api = PZAPI.ModOptions
local group = api:getOptions("LivingFellows")

assert(group ~= nil and group:getOption("pzOptimizerCompatibility") ~= nil, "optional optimizer setting registered")
assert(user.get("terminalLamp")=="flash","movement lamp defaults to Flash")
assert(user.get("banditsCompatibility") == true, "Bandits compatibility defaults on")
assert(user.get("alifeCompatibility") == true, "A-Life compatibility defaults on")
assert(user.get("pzOptimizerCompatibility") == true, "optimizer compatibility defaults on")
assert(user.get("chatter") == "normal", "chatter default before load")
assert(user.get("coughSneezes") == "normal", "cough default before load")
assert(user.get("ordinaryColds") == true, "ordinary colds default before load")
assert(user.get("protectRecruitedCompanions") == false,
    "friendly-fire protection default before load")

local loaded, reason = user.load()
assert(loaded == true, tostring(reason))
assert(#api.Data == 1, "legacy preference intake has no second Options group")
assert(user.get("chatter") == "rare", "current chatter wins over later legacy row")
assert(user.get("coughSneezes") == "rare", "saved cough setting loaded")
assert(user.get("ordinaryColds") == false, "saved cold setting loaded")
assert(user.get("banditsCompatibility") == false, "saved Bandits Off setting loaded")
assert(user.get("alifeCompatibility") == false, "current A-Life Off wins over legacy On")
assert(user.get("pzOptimizerCompatibility") == false, "legacy optimizer Off migrates")
assert(user.get("terminalLamp") == "steady", "legacy lamp choice migrates")
assert(user.get("speechColors") == "speaker", "invalid legacy choice preserves default")
assert(#SC_TEST_MOD_OPTIONS_DISK() == 12, "loading preferences leaves the original file intact")
assert(user.get("protectRecruitedCompanions") == true,
    "saved player-attack protection loaded")
assert(SCBridge.calls[#SCBridge.calls] == true, "saved protection synced to native gate")
local savedComfort = SCBridge.comfortCalls[#SCBridge.comfortCalls]
assert(savedComfort.mode == "rare" and savedComfort.ordinaryColds == false,
    "saved comfort choices reach the native constructor defaults")
assert(LivingFellows.Gestures.nativeOptionApplies == 1,
    "saved symptom preferences sent to native actors")

-- MainOptions applies widget values, then calls each options:apply() and saves.
group:getOption("chatter"):setValue(2)
group:getOption("coughSneezes"):setValue(3)
group:getOption("ordinaryColds"):setValue(true)
group:getOption("banditsCompatibility"):setValue(true)
group:getOption("alifeCompatibility"):setValue(true)
group:getOption("pzOptimizerCompatibility"):setValue(false)
group:getOption("protectRecruitedCompanions"):setValue(false)
group:apply()
assert(user.get("chatter") == "less", "Apply updates chatter live")
assert(user.get("coughSneezes") == "off", "Apply updates coughs live")
assert(user.get("ordinaryColds") == true, "Apply updates colds live")
assert(user.get("pzOptimizerCompatibility") == false, "optimizer Off applies live")
assert(user.get("protectRecruitedCompanions") == false,
    "Apply updates protection live")
assert(SCBridge.calls[#SCBridge.calls] == false, "Apply updates native gate live")
local liveComfort = SCBridge.comfortCalls[#SCBridge.comfortCalls]
assert(liveComfort.mode == "off" and liveComfort.ordinaryColds == true,
    "Apply updates native constructor defaults live")
assert(LivingFellows.Gestures.nativeOptionApplies == 2,
    "Apply updates existing companions immediately")

assert(user.get("speechColors") == "speaker")
group:getOption("speechColors"):setValue(2)
group:apply()
assert(user.get("speechColors") == "white", "white option applies live")
api:save()
local disk = SC_TEST_MOD_OPTIONS_DISK()
assert(disk[7] == "tickbox|LivingFellows|pzOptimizerCompatibility|false")
assert(disk[8] == "combobox|LivingFellows|speechColors|2")
assert(disk[1] == "combobox|LivingFellows|chatter|2")
assert(disk[2] == "combobox|LivingFellows|coughSneezes|3")
assert(disk[3] == "tickbox|LivingFellows|ordinaryColds|true")
assert(disk[4] == "tickbox|LivingFellows|protectRecruitedCompanions|false")
assert(disk[5] == "tickbox|LivingFellows|banditsCompatibility|true")
assert(disk[6] == "tickbox|LivingFellows|alifeCompatibility|true")
assert(disk[9] == "combobox|LivingFellows|terminalLamp|2", "Apply stores migrated settings under the current ID")
assert(disk[#disk] == "tickbox|AnotherMod|enabled|false", "Apply retains the unrelated row")
for _, row in ipairs(disk) do
    assert(not row:find("|SurvivorCompanion|", 1, true), "Apply retires the migrated preference rows")
end

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
assert(user.get("pzOptimizerCompatibility") == false, "optimizer Off survives reload")

SC_TEST_SET_MOD_OPTIONS_DISK({
    "combobox|LivingFellows|chatter|99",
    "combobox|LivingFellows|coughSneezes|0",
})
assert(user.load() == true)
assert(user.get("chatter") == "normal", "invalid chatter index uses default")
assert(user.get("coughSneezes") == "normal", "invalid cough index uses default")

assert(user.get("speechColors") == "white", "white option survives reload")
group:getOption("speechColors"):setValue(99)
group:apply()
assert(user.get("speechColors") == "speaker", "malformed colour option uses default")
SC_TEST_REPORT = "SCUserOptions legacy migration, persistence and live Apply PASS"
