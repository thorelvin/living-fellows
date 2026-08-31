-- SPDX-License-Identifier: MIT

if SurvivorCompanion == nil then
    SurvivorCompanion = {}
end

local SC = SurvivorCompanion

SC.Identity = SC.Identity or {
    displayName = "Living Fellows: Companion",
    modId = "SurvivorCompanion",
    release = "0.22.7",
    gameVersion = "42.20.4",
    bridgeProtocol = "42.20-isocompanion-5",
    saveKey = "SC_SaveV1",
    -- Schema 2 stores a complete recursive inventory tree plus worn/hand
    -- equipment.  The save key intentionally remains stable so schema 1
    -- documents can be migrated in place by SCPersistence.
    saveSchema = 2,
}

SC.Modules = SC.Modules or {}
SC.State = SC.State or {
    generation = 0,
    active = false,
    disabledReason = nil,
}

return SC
