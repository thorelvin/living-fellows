-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local survivor = { id = "sc-survivor" }
local stranger = { id = "sc-stranger" }
SC_TEST_NICKNAME_SURVIVOR = survivor
SC_TEST_NICKNAME_STRANGER = stranger
SC.GameplayUtil = {
    nowMs = function() return 100000 end,
    config = function() return nil end,
    idOf = function(value) return value and value.id end,
    isDead = function() return false end,
    registryLiving = function() return { survivor, stranger } end,
    stableHash = function() return 7 end,
}
SC.Commands = {
    peek = function(actor)
        return (actor == survivor or actor == stranger)
            and { recruited = true } or nil
    end,
}
