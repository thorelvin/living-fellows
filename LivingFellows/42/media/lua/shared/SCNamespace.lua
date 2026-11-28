-- SPDX-License-Identifier: MIT

if LivingFellows == nil then
    LivingFellows = {}
end

local SC = LivingFellows

SC.Identity = SC.Identity or {
    displayName = "Living Fellows",
    modId = "LivingFellows",
    release = "0.27.107",
    gameVersion = "42.22.2",
    bridgeProtocol = "42.22-isocompanion-38",
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
