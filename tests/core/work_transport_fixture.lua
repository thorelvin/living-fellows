-- SPDX-License-Identifier: MIT

-- SCBaseWork derives its native build action class at module load. Gathering
-- never invokes it, but the coupled dispatcher harness still loads the real
-- production module and therefore supplies the smallest faithful class seam.
ISBuildAction = ISBuildAction or {}

function ISBuildAction:derive(name)
    local class = { Type = name }
    setmetatable(class, { __index = self })
    class.__index = class
    return class
end

function ISBuildAction:perform()
    return true
end

return true
