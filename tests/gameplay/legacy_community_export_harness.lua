-- SPDX-License-Identifier: MIT
-- Execute only with the archived 0.27.18 production sources. This generates a
-- real old-format serialization rather than reconstructing it in the new code.
local SC=SurvivorCompanion
assert(SC.Identity.release=="0.27.18","legacy fixture must come from 0.27.18 sources")
SC.Community.reset() SC.LifeEvents.reset()
SC.LifeEvents.emit("worked",{participants={"sc-legacy-1"},sourceId="sc-legacy-1"})
SC.LifeEvents.emit("shared_escape",{participants={"sc-legacy-1","sc-legacy-2"},sourceId="sc-legacy-1"})
SC.Community.processEvents(32)
local function encode(value)
    local kind=type(value)
    if kind=="string" then return string.format("%q",value) end
    if kind=="number" or kind=="boolean" then return tostring(value) end
    assert(kind=="table","old export contains an unstable value")
    local keys={} for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local parts={}
    for _,key in ipairs(keys) do parts[#parts+1]="["..encode(key).."]="..encode(value[key]) end
    return "{"..table.concat(parts,",").."}"
end
SC_TEST_REPORT="LEGACY_COMMUNITY_BEGIN\n-- SPDX-License-Identifier: MIT\n-- Exported by the actual 0.27.18 Kahlua modules.\nSC_TEST_LEGACY_COMMUNITY="
    ..encode(SC.Community.export()).."\nLEGACY_COMMUNITY_END\n"
