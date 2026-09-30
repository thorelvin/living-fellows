-- SPDX-License-Identifier: MIT
SurvivorCompanion = {
    UI = { text = function(key, argument)
        return argument and (key .. ":" .. tostring(argument)) or key
    end },
    Commands = { issue = function(id, action)
        return true, id .. ":" .. action
    end },
}
SCSplitScreenProbe = nil
