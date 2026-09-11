-- SPDX-License-Identifier: MIT

if SurvivorCompanion == nil then
    SurvivorCompanion = {}
end

local SC = SurvivorCompanion

SC.Identity = SC.Identity or {
    displayName = "Living Fellows: Companion",
    modId = "SurvivorCompanion",
    release = "0.22.15",
    gameVersion = "42.20.4",
    bridgeProtocol = "42.20-isocompanion-7",
    worldSaveKey = "SC_WorldV1",
    -- Schema 3 moves the complete world document out of character ModData.
    -- Inventory nodes retain their independent schema-2 representation.
    saveSchema = 3,
}
SC.Identity.providers = {
    native = "iso-companion",
    experimental = "experimental-npc-player",
    test = "test",
}

SC.Modules = SC.Modules or {}
SC.State = SC.State or {
    generation = 0,
    active = false,
    disabledReason = nil,
}

return SC
