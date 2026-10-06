-- SPDX-License-Identifier: MIT

-- BaseWork only binds these helpers while loading. The recipe test supplies
-- the build API separately and does not run companion work actions.
SurvivorCompanion.NativeList = { size = function() return 0 end,
    get = function() return nil end }
SurvivorCompanion.GameplayUtil = { call = function(object, method, ...)
    local callback = object and object[method]
    if type(callback) ~= "function" then return nil, false end
    return callback(object, ...), true
end }
ISBuildAction = { derive = function()
    return {}
end }
