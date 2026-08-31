-- SPDX-License-Identifier: MIT

require "SCNamespace"

local SC = SurvivorCompanion
SC.Net = SC.Net or {}

SC.Net.enabled = false

function SC.Net.isAuthoritative()
    return false
end

function SC.Net.send()
    return false, "networking is unavailable in the single-player release"
end

function SC.Net.reset()
end

return SC.Net
