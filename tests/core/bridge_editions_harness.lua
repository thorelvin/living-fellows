-- SPDX-License-Identifier: MIT
-- Which Living Fellows copy's Lua loaded, against which copy supplied the
-- bridge. Project Zomboid loads one copy's Lua by folder order (upload staging,
-- Workshop, Zomboid\mods); the standalone launcher loads its bridge first.
local SC = LivingFellows
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local savedBridge, savedLookup = rawget(_G, "SCBridge"), rawget(_G, "getModInfoByID")
local savedFolders, savedDetails = rawget(_G, "getModDirectoryTable"), rawget(_G, "getModInfo")
local lookups = 0

local function install(source, origin, release)
    rawset(_G, "getModInfoByID", function(id)
        lookups = lookups + 1
        if id ~= "LivingFellows" then return nil end
        return { getSource = function() return source end }
    end)
    if origin then
        rawset(_G, "SCBridge", {
            getBridgeOrigin = function() return origin end,
            getBridgeRelease = function() return release or SC.Identity.release end,
        })
    else
        rawset(_G, "SCBridge", nil)
    end
    SC.Actor._resetEditionStatus()
end

install("Steam", "launcher", "0.27.58")
local status = SC.Actor.editionStatus()
check(status.luaSource == "workshop" and status.bridgeOrigin == "launcher" and status.mixed == true,
    "a Workshop copy running on the standalone launcher bridge is two editions mixed")
check(status.bridgeRelease == "0.27.58" and status.luaRelease == SC.Identity.release,
    "both releases are reported for Support")
install("Workshop", "launcher")
check(SC.Actor.editionStatus().luaSource == "staging" and SC.Actor.editionStatus().mixed == true,
    "an upload staging copy on the launcher bridge is mixed too")
install("Mods", "launcher")
check(SC.Actor.editionStatus().mixed == false, "the standalone copy on its own launcher bridge is one edition")
install("Steam", "workshop")
check(SC.Actor.editionStatus().mixed == false,
    "the Workshop copy with the bridge ZombieBuddy loaded from it is one edition")

install("Steam", nil)
local early = SC.Actor.editionStatus()
check(early.mixed == false and early.bridgeOrigin == "unknown", "before the bridge is published nothing is compared")
rawset(_G, "SCBridge", {
    getBridgeOrigin = function() return "launcher" end,
    getBridgeRelease = function() return "0.27.60" end,
})
check(SC.Actor.editionStatus().mixed == true, "the comparison is made once the bridge is published")
local seen = lookups
SC.Actor.editionStatus(); SC.Actor.editionStatus()
check(lookups == seen, "the answer is kept for the session instead of asked every second")

install("Steam", "launcher")
rawset(_G, "SCBridge", { getProtocol = function() return "42.22-isocompanion-31" end })
SC.Actor._resetEditionStatus()
local older = SC.Actor.editionStatus()
check(older.mixed == false and older.bridgeOrigin == "unknown",
    "a bridge too old to say where it came from is not guessed at")

local localFolder, steamFolder = "C:\\Zomboid\\mods\\LivingFellows", "D:/steamapps/mods/LivingFellows"
local legacyFolder = "C:/Zomboid/mods/SurvivorCompanion"
local paths, folderScans = { steamFolder, "C:/Zomboid/mods/OtherMod", localFolder }, 0
rawset(_G, "getModDirectoryTable", function()
    folderScans = folderScans + 1
    return paths
end)
rawset(_G, "getModInfo", function(path)
    check(path == localFolder or path == legacyFolder or path == steamFolder, "only Living Fellows folders are inspected")
    return {
        getSource = function() return path == steamFolder and "Steam" or "Mods" end,
        getId = function() return path == legacyFolder and "SurvivorCompanion" or "LivingFellows" end,
        getDescription = function() return "Uses the bundled standalone bridge installer." end,
        getModVersion = function() return "0.27.58" end,
    }
end)
SC.Actor._resetEditionStatus()
older = SC.Actor.editionStatus()
check(older.mixed == false and older.bridgeOrigin == "unknown" and older.standaloneRelease == "0.27.58",
    "an older bridge still reports the separately installed standalone copy and its actual mod version")
local offline = SC.Support.snapshot(true).bridge.advice
check(offline:find("local standalone copy (0.27.58)", 1, true) ~= nil and folderScans == 1,
    "Support identifies the old installation while leaving the bridge origin unknown")
check(SC.Support.summary(true):find("| standalone install 0.27.58 | two editions installed", 1, true) ~= nil,
    "the support report includes the old standalone installation")
paths = { steamFolder, legacyFolder }
install("Steam", "workshop")
check(SC.Actor.editionStatus().standaloneRelease == "0.27.58",
    "a Workshop copy still detects an installation made before the mod ID changed")
check(not SC.Support.summary(true):find("SurvivorCompanion", 1, true),
    "the support report uses the current name for the earlier installed edition")
paths = { steamFolder }
install("Steam", nil)
check(SC.Actor.editionStatus().standaloneRelease == nil, "an ordinary Workshop install has no local edition")
rawset(_G, "getModDirectoryTable", savedFolders)
rawset(_G, "getModInfo", savedDetails)

-- Support explains the fix and the copied report records both sides.
install("Steam", "launcher", "0.27.58")
local snapshot = SC.Support.snapshot(true)
check(snapshot.bridge.advice:find("Uninstall.bat", 1, true) ~= nil
    and snapshot.bridge.advice:find("Steam Workshop copy", 1, true) ~= nil
    and snapshot.bridge.advice:find("0.27.58", 1, true) ~= nil,
    "Support advice names the Workshop copy, the bridge release and how to keep one edition")
local report = SC.Support.summary(true)
check(report:find("Editions: mod workshop " .. SC.Identity.release .. " | bridge launcher 0.27.58 | two editions mixed", 1, true) ~= nil,
    "the copied report records both editions without any local path")
install("Mods", "launcher")
check(SC.Support.snapshot(true).bridge.advice:find("Uninstall.bat", 1, true) == nil,
    "one edition keeps the ordinary bridge advice")

rawset(_G, "SCBridge", savedBridge)
rawset(_G, "getModInfoByID", savedLookup)
SC.Actor._resetEditionStatus()
print("BRIDGE_EDITIONS_PASS checks=" .. checks)
